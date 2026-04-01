// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-cardano-uplc",
    platforms: [
        .macOS(.v15),
        .iOS(.v17),
    ],
    products: [
        .library(name: "SwiftCardanoUPLC", targets: ["SwiftCardanoUPLC"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Kingpin-Apps/swift-cardano-core.git", from: "0.2.26"),
        .package(url: "https://github.com/Kingpin-Apps/swift-cardano-chain.git", from: "0.1.0"),
        .package(url: "https://github.com/Kingpin-Apps/swift-blst.git", from: "0.1.2"),
        .package(url: "https://github.com/Kingpin-Apps/swift-ncal.git", from: "0.2.2"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "1.9.0"),
        .package(url: "https://github.com/21-DOT-DEV/swift-secp256k1", exact: "0.22.0"),
        .package(url: "https://github.com/attaswift/BigInt.git", from: "5.3.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "SwiftCardanoUPLC",
            dependencies: [
                .product(name: "SwiftCardanoCore", package: "swift-cardano-core"),
                .product(name: "SwiftCardanoChain", package: "swift-cardano-chain"),
                .product(name: "SwiftBLST", package: "swift-blst"),
                .product(name: "SwiftNcal", package: "swift-ncal"),
                .product(name: "CryptoSwift", package: "CryptoSwift"),
                .product(name: "P256K", package: "swift-secp256k1"),
                .product(name: "libsecp256k1", package: "swift-secp256k1"),
                .product(name: "BigInt", package: "BigInt"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .testTarget(
            name: "SwiftCardanoUPLCTests",
            dependencies: ["SwiftCardanoUPLC"],
            resources: [.copy("Resources")]
        ),
    ]
)
