// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "WalletCore",
    platforms: [.iOS(.v13)],
    products: [
        .library(name: "WalletCore", targets: ["WalletCore"]),
        .library(
            name: "WalletCoreSwiftProtobuf",
            targets: ["WalletCoreSwiftProtobuf"]
        )
    ],
    dependencies: [],
    targets: [
        .binaryTarget(
            name: "WalletCore",
            url: "https://github.com/trustwallet/wallet-core/releases/download/4.6.13/WalletCore.xcframework.zip",
            checksum: "fab9f3f823bc8f089bfcb9aeedb5382d98ae9b2668fe74cfd01c227c8b5d9c97"
        ),
        .binaryTarget(
            name: "WalletCoreSwiftProtobuf",
            url: "https://github.com/trustwallet/wallet-core/releases/download/4.6.13/WalletCoreSwiftProtobuf.xcframework.zip",
            checksum: "78646b25cd2dca3014f55fb2c4659c6df5e68852bd692e1518626a213c114f60"
        )
    ]
)
