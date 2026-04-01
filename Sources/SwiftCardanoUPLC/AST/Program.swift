/// A complete UPLC program with version information.
public struct Program<T: Sendable & Hashable>: Sendable {
    /// Semantic version of the UPLC program (major, minor, patch).
    public let version: (UInt, UInt, UInt)
    public let term: Term<T>

    public init(version: (UInt, UInt, UInt), term: Term<T>) {
        self.version = version
        self.term = term
    }
}

/// Type aliases for the three program forms used throughout the lifecycle.
public typealias NamedProgram = Program<Name>
public typealias DeBruijnProgram = Program<DeBruijn>
public typealias NamedDeBruijnProgram = Program<NamedDeBruijn>
