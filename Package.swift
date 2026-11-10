// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Vutidy",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Vutidy", targets: ["Vutidy"]),
        .executable(name: "vutidy-cli", targets: ["vutidy-cli"]),
    ],
    targets: [
        .target(name: "CoreKit"),
        .target(name: "SafetyLayer", dependencies: ["CoreKit"]),
        .target(name: "ScanEngine", dependencies: ["CoreKit"]),
        .target(name: "RuleEngine", dependencies: ["CoreKit", "ScanEngine", "SafetyLayer"],
                resources: [.copy("Resources")]),
        .target(name: "Modules", dependencies: ["CoreKit", "SafetyLayer", "ScanEngine", "RuleEngine"]),
        .executableTarget(name: "Vutidy", dependencies: ["Modules"], resources: [.copy("Resources")]),
        .executableTarget(name: "vutidy-cli", dependencies: ["Modules"]),
        .testTarget(name: "VutidyTests", dependencies: ["CoreKit", "SafetyLayer", "ScanEngine", "RuleEngine", "Modules"]),
    ]
)
