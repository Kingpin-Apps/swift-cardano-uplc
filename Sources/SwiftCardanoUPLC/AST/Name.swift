/// A unique integer identifier for interned strings during parsing.
public struct Unique: Hashable, Sendable {
    public let value: Int
    public init(_ value: Int) { self.value = value }
}

/// A named variable as it appears in textual UPLC.
public struct Name: Hashable, Sendable {
    public let text: String
    public let unique: Unique
    public init(text: String, unique: Unique) {
        self.text = text
        self.unique = unique
    }
}

/// A De Bruijn index — replaces names in encoded programs.
/// Index 1 refers to the nearest enclosing lambda, 2 the next, etc.
public struct DeBruijn: Hashable, Sendable {
    public let index: UInt
    public init(_ index: UInt) { self.index = index }
    public static let zero = DeBruijn(0)
}

/// Hybrid form: name + De Bruijn index (intermediate representation).
public struct NamedDeBruijn: Hashable, Sendable {
    public let text: String
    public let index: DeBruijn
    public init(text: String, index: DeBruijn) {
        self.text = text
        self.index = index
    }
}

/// Synthetic wrapper used during flat decoding when names aren't available.
public struct FakeNamedDeBruijn: Hashable, Sendable {
    public let inner: NamedDeBruijn
    public init(_ inner: NamedDeBruijn) { self.inner = inner }
}
