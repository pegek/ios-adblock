// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BuildRules",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "build-rules", targets: ["BuildRules"]),
    ],
    dependencies: [
        .package(url: "https://github.com/AdguardTeam/SafariConverterLib.git", exact: "4.3.0"),
    ],
    targets: [
        .target(
            name: "RulesCore",
            dependencies: [
                .product(name: "ContentBlockerConverter", package: "SafariConverterLib"),
            ]
        ),
        .executableTarget(name: "BuildRules", dependencies: ["RulesCore"]),
        .testTarget(name: "RulesCoreTests", dependencies: ["RulesCore"]),
    ]
)
