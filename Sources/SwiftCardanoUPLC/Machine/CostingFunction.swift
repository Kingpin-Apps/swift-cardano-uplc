import Foundation

/// A builtin costing function: maps the sizes of a builtin's arguments to a cost.
///
/// These mirror the `Model*Arguments` families in
/// `PlutusCore.Evaluation.Machine.CostingFun.Core`. The reference implementation
/// evaluates them over lazy cost *streams*; every stream is summed before use,
/// so working with the total size of each argument is equivalent.
///
/// Argument positions are named after the reference implementation: `x`, `y`,
/// `z`, `u` are the first, second, third and fourth arguments.
public indirect enum CostingFunction: Sendable, Equatable {
    /// Independent of the arguments.
    case constant(Int64)

    // One-variable linear models: `intercept + slope * size`.
    case linearInX(intercept: Int64, slope: Int64)
    case linearInY(intercept: Int64, slope: Int64)
    case linearInZ(intercept: Int64, slope: Int64)
    case linearInU(intercept: Int64, slope: Int64)

    /// `intercept + slope * (x + y)`
    case addedSizes(intercept: Int64, slope: Int64)
    /// `intercept + slope * max(minimum, x - y)`
    case subtractedSizes(intercept: Int64, slope: Int64, minimum: Int64)
    /// `intercept + slope * (x * y)`
    case multipliedSizes(intercept: Int64, slope: Int64)
    /// `intercept + slope * min(x, y)`
    case minSize(intercept: Int64, slope: Int64)
    /// `intercept + slope * max(x, y)`
    case maxSize(intercept: Int64, slope: Int64)

    /// `intercept + slopeX * x + slopeY * y`
    case linearInXAndY(intercept: Int64, slopeX: Int64, slopeY: Int64)
    /// `intercept + slopeY * y + slopeZ * z`
    case linearInYAndZ(intercept: Int64, slopeY: Int64, slopeZ: Int64)
    /// `intercept + slope * max(y, z)`
    case linearInMaxYZ(intercept: Int64, slope: Int64)
    /// `y` when `y` is non-zero, otherwise `intercept + slope * z`.
    case literalInYOrLinearInZ(intercept: Int64, slope: Int64)

    // Single-variable quadratics: `c0 + c1 * s + c2 * s^2`.
    case quadraticInX(c0: Int64, c1: Int64, c2: Int64)
    case quadraticInY(c0: Int64, c1: Int64, c2: Int64)
    case quadraticInZ(c0: Int64, c1: Int64, c2: Int64)

    /// `max(minimum, c00 + c10*a + c01*b + c20*a^2 + c11*a*b + c02*b^2)` over
    /// the first and second arguments.
    case quadraticInXAndY(TwoVariableQuadratic)
    /// The same, over the second and third arguments.
    case quadraticInYAndZ(TwoVariableQuadratic)

    /// `c00 + c10*x + c01*y + c11*x*y`
    case withInteractionInXAndY(c00: Int64, c10: Int64, c01: Int64, c11: Int64)

    /// `expModInteger`: `c00 + c11*e*m + c12*e*m^2`, plus 50% when `a > m`.
    case expModCost(c00: Int64, c11: Int64, c12: Int64)

    /// Constant when `x != y`, otherwise `intercept + slope * x`.
    case linearOnDiagonal(constant: Int64, intercept: Int64, slope: Int64)
    /// Constant when `x < y`, otherwise the nested model.
    case constAboveDiagonal(constant: Int64, model: CostingFunction)
    /// Constant when `x > y`, otherwise the nested model.
    case constBelowDiagonal(constant: Int64, model: CostingFunction)
    /// Constant when `x != y`, otherwise the nested model applied to `x`.
    case constOffDiagonal(constant: Int64, model: CostingFunction)

    /// Coefficients of a two-variable quadratic, with a floor.
    public struct TwoVariableQuadratic: Sendable, Equatable {
        public var minimum: Int64
        public var c00: Int64
        public var c10: Int64
        public var c01: Int64
        public var c20: Int64
        public var c11: Int64
        public var c02: Int64

        public init(
            minimum: Int64, c00: Int64, c10: Int64, c01: Int64,
            c20: Int64, c11: Int64, c02: Int64
        ) {
            self.minimum = minimum
            self.c00 = c00
            self.c10 = c10
            self.c01 = c01
            self.c20 = c20
            self.c11 = c11
            self.c02 = c02
        }

        func evaluate(_ x: Int64, _ y: Int64) -> Int64 {
            // The reference implementation floors this: the fitted polynomial
            // can go negative for small inputs, and a negative cost would
            // refund budget.
            let value = c00 &+ c10 &* x &+ c01 &* y
                &+ c20 &* x &* x &+ c11 &* x &* y &+ c02 &* y &* y
            return max(minimum, value)
        }
    }

    /// Evaluate this function against the sizes of a builtin's arguments.
    ///
    /// `sizes` is positional; a model that names an argument the builtin does
    /// not have returns 0 rather than trapping, which cannot happen for a
    /// correctly wired builtin.
    public func cost(_ sizes: [Int64]) -> Int64 {
        func size(_ index: Int) -> Int64 {
            index < sizes.count ? sizes[index] : 0
        }
        let x = size(0), y = size(1), z = size(2), u = size(3)

        switch self {
        case .constant(let c):
            return c

        case .linearInX(let i, let s): return i &+ s &* x
        case .linearInY(let i, let s): return i &+ s &* y
        case .linearInZ(let i, let s): return i &+ s &* z
        case .linearInU(let i, let s): return i &+ s &* u

        case .addedSizes(let i, let s):      return i &+ s &* (x &+ y)
        case .subtractedSizes(let i, let s, let minimum):
            return i &+ s &* max(minimum, x &- y)
        case .multipliedSizes(let i, let s): return i &+ s &* (x &* y)
        case .minSize(let i, let s):         return i &+ s &* min(x, y)
        case .maxSize(let i, let s):         return i &+ s &* max(x, y)

        case .linearInXAndY(let i, let sx, let sy): return i &+ sx &* x &+ sy &* y
        case .linearInYAndZ(let i, let sy, let sz): return i &+ sy &* y &+ sz &* z
        case .linearInMaxYZ(let i, let s):          return i &+ s &* max(y, z)
        case .literalInYOrLinearInZ(let i, let s):
            return y == 0 ? i &+ s &* z : y

        case .quadraticInX(let c0, let c1, let c2): return c0 &+ c1 &* x &+ c2 &* x &* x
        case .quadraticInY(let c0, let c1, let c2): return c0 &+ c1 &* y &+ c2 &* y &* y
        case .quadraticInZ(let c0, let c1, let c2): return c0 &+ c1 &* z &+ c2 &* z &* z

        case .quadraticInXAndY(let f): return f.evaluate(x, y)
        case .quadraticInYAndZ(let f): return f.evaluate(y, z)

        case .withInteractionInXAndY(let c00, let c10, let c01, let c11):
            return c10 &* x &+ c01 &* y &+ c11 &* (x &* y) &+ c00

        case .expModCost(let c00, let c11, let c12):
            let base = c00 &+ c11 &* y &* z &+ c12 &* y &* z &* z
            // A base larger than the modulus costs 50% more, for the initial
            // reduction.
            return x <= z ? base : base &+ base / 2

        case .linearOnDiagonal(let c, let i, let s):
            return x == y ? i &+ s &* x : c
        case .constAboveDiagonal(let c, let model):
            return x < y ? c : model.cost(sizes)
        case .constBelowDiagonal(let c, let model):
            return x > y ? c : model.cost(sizes)
        case .constOffDiagonal(let c, let model):
            return x != y ? c : model.cost([x])
        }
    }
}

/// The CPU and memory costing functions for one builtin.
public struct BuiltinCostingFunction: Sendable, Equatable {
    public var cpu: CostingFunction
    public var memory: CostingFunction

    public init(cpu: CostingFunction, memory: CostingFunction) {
        self.cpu = cpu
        self.memory = memory
    }

    /// The budget this builtin consumes for arguments of the given sizes.
    public func budget(sizes: [Int64]) -> ExBudget {
        ExBudget(cpu: cpu.cost(sizes), mem: memory.cost(sizes))
    }
}
