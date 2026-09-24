/// Internal machine state.
private enum MachineState: Sendable {
    /// Computing a term in a given environment with the given continuation.
    case compute(Context, Environment, Term<NamedDeBruijn>)
    /// Returning a value to the continuation.
    case returning(Context, Value)
    /// Evaluation is complete.
    case done(Term<NamedDeBruijn>)
}

/// CEK (Control, Environment, Continuation) evaluator for UPLC.
public struct CEKMachine: Sendable {
    private var budget: ExBudget
    private let costModel: CostModel
    private var logs: [String]
    /// Number of unbudgeted steps to batch before spending budget.
    private let slippage: Int = 200
    private var unbudgetedSteps: [Int: Int32] = [:]

    public init(budget: ExBudget = .restricted, costModel: CostModel) {
        self.budget = budget
        self.costModel = costModel
        self.logs = []
    }

    /// Evaluate a NamedDeBruijn program and return the result.
    public mutating func run(_ program: NamedDeBruijnProgram) throws -> EvalResult {
        logs = []
        try spendBudget(costModel.machineStepCosts.startup)

        var state = MachineState.compute(.noFrame, Environment(), program.term)

        while true {
            switch state {
            case .compute(let ctx, let env, let term):
                state = try computeStep(ctx, env, term)
            case .returning(let ctx, let value):
                state = try returnStep(ctx, value)
            case .done(let term):
                try spendUnbudgetedSteps()
                return EvalResult(term: term, remainingBudget: budget, logs: logs)
            }
        }
    }

    // MARK: — Compute step (term → value or new computation)

    private mutating func computeStep(
        _ ctx: Context,
        _ env: Environment,
        _ term: Term<NamedDeBruijn>
    ) throws -> MachineState {
        switch term {
        case .var(let name):
            try stepAndMaybeSpend(\.variable)
            let value = try env.lookup(name.index)
            return .returning(ctx, value)

        case .delay(let body):
            try stepAndMaybeSpend(\.delay)
            return .returning(ctx, .delay(body, env))

        case .lambda(let param, let body):
            try stepAndMaybeSpend(\.lambda)
            return .returning(ctx, .lambda(parameterName: param, body: body, env: env))

        case .apply(let f, let arg):
            try stepAndMaybeSpend(\.apply)
            // Evaluate the function first, then the argument
            return .compute(.frameAwaitFunTerm(env, arg, ctx), env, f)

        case .constant(let c):
            try stepAndMaybeSpend(\.constant)
            return .returning(ctx, .con(c))

        case .force(let body):
            try stepAndMaybeSpend(\.force)
            return .compute(.frameForce(ctx), env, body)

        case .error:
            throw MachineError.evaluationFailure

        case .builtin(let fn):
            try stepAndMaybeSpend(\.builtin)
            return .returning(ctx, .partiallyApplied(fn, [], forces: 0))

        case .constr(let tag, let fields):
            try stepAndMaybeSpend(\.constr)
            if fields.isEmpty {
                return .returning(ctx, .constr(tag: tag, fields: []))
            }
            let remaining = Array(fields.dropFirst())
            return .compute(.frameConstr(env, tag, remaining, [], ctx), env, fields[0])

        case .case(let arg, let branches):
            try stepAndMaybeSpend(\.kase)
            return .compute(.frameCases(env, branches, ctx), env, arg)
        }
    }

    // MARK: — Return step (value → apply continuation)

    private mutating func returnStep(_ ctx: Context, _ value: Value) throws -> MachineState {
        switch ctx {
        case .noFrame:
            return .done(try dischargeTo(value))

        case .frameAwaitFunTerm(let env, let argTerm, let outer):
            // `value` is the function result; now evaluate the argument,
            // storing the function value in the frame.
            return .compute(.frameAwaitFunValue(value, outer), env, argTerm)

        case .frameAwaitFunValue(let funValue, let outer):
            // `value` is the argument result; `funValue` is the function.
            return try applyEvaluate(outer, function: funValue, argument: value)

        case .frameAwaitArg(let funValue, let outer):
            // The argument is now evaluated; apply
            return try applyEvaluate(outer, function: funValue, argument: value)

        case .frameForce(let outer):
            return try forceEvaluate(outer, value: value)

        case .frameConstr(let env, let tag, let remaining, var seen, let outer):
            seen.append(value)
            if remaining.isEmpty {
                return .returning(outer, .constr(tag: tag, fields: seen))
            }
            let next = remaining[0]
            let rest = Array(remaining.dropFirst())
            return .compute(.frameConstr(env, tag, rest, seen, outer), env, next)

        case .frameCases(let env, let branches, let outer):
            guard case .constr(let tag, let fields) = value else {
                throw MachineError.typeError("case: expected constr value")
            }
            guard Int(tag) < branches.count else {
                throw MachineError.missingCaseBranch(tag)
            }
            // Plutus semantics: case (constr tag f1..fn) b0..bm => [b_tag f1 ... fn]
            // Evaluate the selected branch, then apply each field as an argument.
            if fields.isEmpty {
                return .compute(outer, env, branches[Int(tag)])
            }
            // Compute the branch first; frameCaseApplyFields will apply fields after
            return .compute(.frameCaseApplyFields(fields, outer), env, branches[Int(tag)])

        case .frameCaseApplyFields(var fields, let outer):
            // The branch has been evaluated to `value`; apply the next field.
            let nextField = fields.removeFirst()
            if fields.isEmpty {
                // Last field: apply and continue with the outer context
                return try applyEvaluate(outer, function: value, argument: nextField)
            } else {
                // More fields remain: apply this one and continue with remaining
                return try applyEvaluate(.frameCaseApplyFields(fields, outer), function: value, argument: nextField)
            }
        }
    }

    // MARK: — Apply / Force

    private mutating func applyEvaluate(_ ctx: Context, function: Value, argument: Value) throws -> MachineState {
        switch function {
        case .lambda(_, let body, let env):
            let newEnv = env.extend(with: argument)
            return .compute(ctx, newEnv, body)

        case .partiallyApplied(let fn, var args, let forces):
            // Plutus requires all forces to be applied before arguments
            guard forces >= fn.forceCount else {
                throw MachineError.nonFunctionalApplication("builtin \(fn) requires \(fn.forceCount) force(s) before arguments")
            }
            args.append(argument)
            if args.count == fn.arity {
                try spendBuiltinBudget(fn, arguments: args)
                let result = try BuiltinRuntime.apply(fn, to: args, costModel: costModel, logs: &logs)
                return .returning(ctx, result)
            } else {
                return .returning(ctx, .partiallyApplied(fn, args, forces: forces))
            }

        default:
            throw MachineError.nonFunctionalApplication("\(function)")
        }
    }

    private mutating func forceEvaluate(_ ctx: Context, value: Value) throws -> MachineState {
        switch value {
        case .delay(let body, let env):
            return .compute(ctx, env, body)

        case .partiallyApplied(let fn, let args, var forces):
            guard forces < fn.forceCount else {
                throw MachineError.forcingNonDelay
            }
            forces += 1
            if forces == fn.forceCount && args.count == fn.arity {
                try spendBuiltinBudget(fn, arguments: args)
                let result = try BuiltinRuntime.apply(fn, to: args, costModel: costModel, logs: &logs)
                return .returning(ctx, result)
            }
            return .returning(ctx, .partiallyApplied(fn, args, forces: forces))

        default:
            throw MachineError.forcingNonDelay
        }
    }

    // MARK: — Budget tracking

    private mutating func stepAndMaybeSpend(_ keyPath: KeyPath<MachineStepCosts, ExBudget>) throws {
        let stepKind = stepIndex(keyPath)
        unbudgetedSteps[stepKind, default: 0] += 1
        if (unbudgetedSteps[stepKind] ?? 0) >= slippage {
            try spendUnbudgetedSteps()
        }
    }

    private mutating func spendUnbudgetedSteps() throws {
        for (kind, count) in unbudgetedSteps {
            let stepCost = stepCostFor(kind)
            try spendBudget(ExBudget(cpu: stepCost.cpu * Int64(count),
                                     mem: stepCost.mem * Int64(count)))
        }
        unbudgetedSteps.removeAll()
    }

    /// Charge a builtin's cost, which depends on the sizes of its arguments.
    ///
    /// Any budget batched up from machine steps is settled first: a builtin
    /// must not be charged before the steps that led to it, or a script can
    /// overshoot the budget by up to one batch.
    private mutating func spendBuiltinBudget(
        _ function: DefaultFunction, arguments: [Value]
    ) throws {
        try spendUnbudgetedSteps()
        guard let cost = costModel.budget(for: function, arguments: arguments) else {
            throw MachineError.typeError(
                "builtin \(function) is not priced by this cost model, so the script's "
                + "Plutus version cannot use it."
            )
        }
        try spendBudget(cost)
    }

    private mutating func spendBudget(_ cost: ExBudget) throws {
        try budget.spend(cpu: cost.cpu, mem: cost.mem)
    }

    // MARK: — Step index helpers

    private func stepIndex(_ keyPath: KeyPath<MachineStepCosts, ExBudget>) -> Int {
        switch keyPath {
        case \MachineStepCosts.startup:  return 9
        case \MachineStepCosts.variable: return 1
        case \MachineStepCosts.constant: return 0
        case \MachineStepCosts.lambda:   return 2
        case \MachineStepCosts.apply:    return 3
        case \MachineStepCosts.delay:    return 4
        case \MachineStepCosts.force:    return 5
        case \MachineStepCosts.builtin:  return 6
        case \MachineStepCosts.constr:   return 7
        case \MachineStepCosts.kase:     return 8
        default:                         return 0
        }
    }

    private func stepCostFor(_ kind: Int) -> ExBudget {
        let c = costModel.machineStepCosts
        switch kind {
        case 0: return c.constant
        case 1: return c.variable
        case 2: return c.lambda
        case 3: return c.apply
        case 4: return c.delay
        case 5: return c.force
        case 6: return c.builtin
        case 7: return c.constr
        case 8: return c.kase
        case 9: return c.startup
        default: return ExBudget(cpu: 0, mem: 0)
        }
    }

    // MARK: — Value → Term discharge (for result)

    private func dischargeTo(_ value: Value) throws -> Term<NamedDeBruijn> {
        switch value {
        case .con(let c):
            return .constant(c)
        case .delay(let body, let env):
            return .delay(try dischargeTerm(body, env: env, depth: 0))
        case .lambda(let param, let body, let env):
            return .lambda(parameterName: param, body: try dischargeTerm(body, env: env, depth: 1))
        case .partiallyApplied(let fn, let args, let forces):
            // Reconstruct: wrap the builtin in the required number of force
            // nodes, then apply the accumulated arguments left-to-right.
            var term: Term<NamedDeBruijn> = .builtin(fn)
            for _ in 0..<forces {
                term = .force(term)
            }
            for arg in args {
                term = .apply(function: term, argument: try dischargeTo(arg))
            }
            return term
        case .constr(let tag, let fields):
            return .constr(tag: tag, fields: try fields.map { try dischargeTo($0) })
        }
    }

    /// Walk a term and substitute variables captured in the closure environment.
    /// `depth` tracks how many binders (lambdas) we're inside relative to the closure.
    /// Variables with index > depth are resolved from the captured environment.
    private func dischargeTerm(
        _ term: Term<NamedDeBruijn>,
        env: Environment,
        depth: UInt
    ) throws -> Term<NamedDeBruijn> {
        switch term {
        case .var(let ndb):
            let idx = ndb.index.index
            if idx > depth {
                // This variable refers to something in the captured environment
                let envIdx = DeBruijn(idx - depth)
                if let val = try? env.lookup(envIdx) {
                    return try dischargeTo(val)
                }
            }
            return term
        case .lambda(let param, let body):
            return .lambda(parameterName: param, body: try dischargeTerm(body, env: env, depth: depth + 1))
        case .apply(let f, let arg):
            return .apply(
                function: try dischargeTerm(f, env: env, depth: depth),
                argument: try dischargeTerm(arg, env: env, depth: depth)
            )
        case .delay(let body):
            return .delay(try dischargeTerm(body, env: env, depth: depth))
        case .force(let body):
            return .force(try dischargeTerm(body, env: env, depth: depth))
        case .constant, .error, .builtin:
            return term
        case .constr(let tag, let fields):
            return .constr(tag: tag, fields: try fields.map { try dischargeTerm($0, env: env, depth: depth) })
        case .case(let arg, let branches):
            return .case(
                argument: try dischargeTerm(arg, env: env, depth: depth),
                branches: try branches.map { try dischargeTerm($0, env: env, depth: depth) }
            )
        }
    }
}
