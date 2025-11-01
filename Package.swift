// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Fair",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14), .iOS(.v17), .tvOS(.v17), .watchOS(.v10)
    ],
    products: [
        .library(name: "FairCore", targets: ["FairCore"]),
        .library(name: "FairExpo", targets: ["FairExpo"]),
        .executable(name: "fairtool", targets: ["fairtool"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.1.3"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/marcprux/universal.git", from: "5.0.3"),
    ],
    targets: [
        .target(name: "CZLib", linkerSettings: [ .linkedLibrary("z") ]),
        .target(name: "FairCore", dependencies: [
            .product(name: "Universal", package: "universal"),
            "CZLib",
        ], resources: [.process("Resources")], cSettings: [.define("_GNU_SOURCE", to: "1")]),
        .target(name: "FairExpo", dependencies: [
            "FairCore",
            .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux])),
        ], resources: [.process("Resources")]),
        .executableTarget(name: "fairtool", dependencies: [
            "FairExpo",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ], resources: [.process("Resources")]),
        .testTarget(name: "FairCoreTests", dependencies: ["FairCore"], resources: [.process("Resources")]),
        .testTarget(name: "FairExpoTests", dependencies: [.target(name: "FairExpo")], resources: [.process("Resources")]),
        .testTarget(name: "FairToolTests", dependencies: [.target(name: "fairtool")], resources: [.process("Resources")]),
    ]
    //swiftLanguageModes: [.v5]
)
