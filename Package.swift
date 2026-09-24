// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftCardanoUPLC",
    platforms: [
        .macOS(.v15),
        .iOS(.v17),
    ],
    products: [
        .library(name: "SwiftCardanoUPLC", targets: ["SwiftCardanoUPLC"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.5.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.12.0"),
        // BigInt 6.x is source-compatible with 5.7.0; the major bump only raised the
        // manifest's tools version. Keep 5.x admissible for consumers still on it.
        .package(url: "https://github.com/attaswift/BigInt.git", "5.7.0"..<"7.0.0"),
        .package(url: "https://github.com/Kingpin-Apps/swift-cardano-core.git", from: "0.5.4"),
        .package(url: "https://github.com/Kingpin-Apps/swift-blst.git", from: "0.1.7"),
        .package(url: "https://github.com/Kingpin-Apps/swift-nacl.git", from: "1.0.2"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "1.9.0"),
        .package(url: "https://github.com/21-DOT-DEV/swift-secp256k1", from: "0.22.0"),
    ],
    targets: [
        .target(
            name: "SwiftCardanoUPLC",
            dependencies: [
                .product(name: "SwiftCardanoCore", package: "swift-cardano-core"),
                .product(name: "SwiftBLST", package: "swift-blst"),
                .product(name: "SwiftNaCl", package: "swift-nacl"),
                .product(name: "CryptoSwift", package: "CryptoSwift"),
                .product(name: "P256K", package: "swift-secp256k1"),
                .product(name: "libsecp256k1", package: "swift-secp256k1"),
                .product(name: "BigInt", package: "BigInt"),
                .product(name: "Logging", package: "swift-log"),
                .product(
                    name: "Crypto",
                    package: "swift-crypto",
                    condition: .when(platforms: [.linux])
                ),
            ]
        ),
        .testTarget(
            name: "SwiftCardanoUPLCTests",
            dependencies: ["SwiftCardanoUPLC"],
            resources: [.copy("Resources")]
        ),
    ]
)
