@preconcurrency import BigInt
import Foundation
import SwiftCardanoCore

/// UPLC constant values.
/// Flat constant tags: Integer=0, ByteString=1, String=2, Unit=3, Bool=4,
/// ProtoList=5, ProtoPair=6, Data=8, G1=9, G2=10, MlResult=11
public indirect enum UPLCConstant: @unchecked Sendable {
    case integer(BigInt)
    case byteString(Data)
    case string(String)
    case unit
    case bool(Bool)
    /// A typed list of constants (ProtoList in Rust).
    case list(UPLCType, [UPLCConstant])
    /// A typed pair of constants (ProtoPair in Rust).
    case pair(UPLCType, UPLCType, UPLCConstant, UPLCConstant)
    /// Plutus on-chain data (PlutusData from SwiftCardanoCore).
    case data(PlutusData)
    /// Compressed G1 point (48 bytes).
    case bls12_381G1Element(Data)
    /// Compressed G2 point (96 bytes).
    case bls12_381G2Element(Data)
    /// Miller loop result (576 bytes).
    case bls12_381MlResult(Data)
}

extension UPLCConstant: Equatable {
    public static func == (lhs: UPLCConstant, rhs: UPLCConstant) -> Bool {
        switch (lhs, rhs) {
        case (.integer(let a), .integer(let b)): return a == b
        case (.byteString(let a), .byteString(let b)): return a == b
        case (.string(let a), .string(let b)): return a == b
        case (.unit, .unit): return true
        case (.bool(let a), .bool(let b)): return a == b
        case (.list(let t1, let a), .list(let t2, let b)): return t1 == t2 && a == b
        case (.pair(let t1a, let t1b, let v1a, let v1b), .pair(let t2a, let t2b, let v2a, let v2b)):
            return t1a == t2a && t1b == t2b && v1a == v2a && v1b == v2b
        case (.data(let a), .data(let b)): return a == b
        case (.bls12_381G1Element(let a), .bls12_381G1Element(let b)): return a == b
        case (.bls12_381G2Element(let a), .bls12_381G2Element(let b)): return a == b
        case (.bls12_381MlResult(let a), .bls12_381MlResult(let b)): return a == b
        default: return false
        }
    }
}
