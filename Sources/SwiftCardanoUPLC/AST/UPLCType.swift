/// UPLC type annotations used in typed constants.
/// Flat constant type tags (4-bit each, compound types prefixed with 7):
///   Integer=0, ByteString=1, String=2, Unit=3, Bool=4
///   List=[7,5,<elem>], Pair=[7,7,6,<t1>,<t2>]
///   Data=8, G1=9, G2=10, MlResult=11
public indirect enum UPLCType: Hashable, Sendable {
    case bool
    case integer
    case string
    case byteString
    case unit
    case list(UPLCType)
    case pair(UPLCType, UPLCType)
    case data
    case bls12_381G1Element
    case bls12_381G2Element
    case bls12_381MlResult
}
