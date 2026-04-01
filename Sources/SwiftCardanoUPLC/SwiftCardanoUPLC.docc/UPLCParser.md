# ``SwiftCardanoUPLC/UPLCParser``

Parse UPLC textual programs into a named AST.

## Overview

`UPLCParser` reads the standard UPLC textual syntax and produces a ``Program`` parameterised over ``Name``. The resulting ``NamedProgram`` can be passed to ``DeBruijnConverter`` for evaluation or flat encoding.

### Accepted syntax

```
program  ::= '(' 'program' version term ')'
version  ::= integer '.' integer '.' integer
term     ::= var | delay | lambda | apply | constant | force | error | builtin | constr | case
var      ::= name
delay    ::= '(' 'delay' term ')'
lambda   ::= '(' 'lam' name term ')'
apply    ::= '[' term term ']'
constant ::= '(' 'con' type value ')'
force    ::= '(' 'force' term ')'
error    ::= '(' 'error' ')'
builtin  ::= '(' 'builtin' builtinName ')'
constr   ::= '(' 'constr' integer term* ')'
case     ::= '(' 'case' term term* ')'
```

### Example

```swift
var parser = UPLCParser()
let program = try parser.parse("""
    (program 1.0.0
      (lam x
        (addInteger x (con integer 1))))
    """)
```

## Topics

### Parsing

- ``parse(_:)``
