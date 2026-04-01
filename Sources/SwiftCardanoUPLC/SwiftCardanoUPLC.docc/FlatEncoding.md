# Flat Encoding

Encode and decode UPLC programs in the on-chain binary format.

## Overview

The **flat** format is a compact, bit-packed binary encoding used on the Cardano blockchain to store Plutus scripts. Bits are packed MSB-first within each byte; integers use a ZigZag + 7-bit-chunk variable-length encoding; byte strings are written as length-prefixed chunks (up to 255 bytes each, terminated by a zero-length chunk), preceded by a byte-alignment filler.

### Encoding

``FlatEncoder`` accepts a ``DeBruijnProgram`` (convert from a ``NamedProgram`` using ``DeBruijnConverter`` first):

```swift
var parser  = UPLCParser()
let named   = try parser.parse(source)
let db      = try DeBruijnConverter().convert(named)
let bytes   = try FlatEncoder().encode(db)      // Data
let hex     = try FlatEncoder().encodeHex(db)   // hex string
```

### Decoding

``FlatDecoder`` produces a ``NamedDeBruijnProgram`` ready for the CEK machine:

```swift
let program = try FlatDecoder().decode(bytes)
let program = try FlatDecoder().decodeHex(hex)
```

### Bit-level I/O

``BitWriter`` and ``BitReader`` are the underlying bit-stream primitives. They are public for advanced use (e.g. building custom flat codecs), but most callers should use ``FlatEncoder`` and ``FlatDecoder`` directly.

## Topics

### High-level codecs

- ``FlatEncoder``
- ``FlatDecoder``
- ``FlatDecodingError``

### Low-level bit I/O

- ``BitWriter``
- ``BitReader``
