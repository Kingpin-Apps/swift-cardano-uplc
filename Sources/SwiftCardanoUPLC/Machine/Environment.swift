/// Variable bindings during CEK evaluation.
/// De Bruijn lookup: index 1 refers to the most recently pushed value (end of array).
/// Matches the Rust implementation: `env.get(env.len() - index)`.
public struct Environment: Sendable {
    private var bindings: [Value]

    public init() { self.bindings = [] }
    private init(bindings: [Value]) { self.bindings = bindings }

    /// Return a new environment with `value` pushed onto the end.
    public func extend(with value: Value) -> Environment {
        Environment(bindings: bindings + [value])
    }

    /// Look up the value at De Bruijn index `index` (1-based from the end).
    public func lookup(_ index: DeBruijn) throws -> Value {
        let i = index.index
        guard i > 0, i <= UInt(bindings.count) else {
            throw MachineError.openTermEvaluated(index)
        }
        return bindings[bindings.count - Int(i)]
    }
}
