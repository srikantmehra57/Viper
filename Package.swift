// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Viper",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Viper", targets: ["Viper"])],
    targets: [
        .target(name: "ViperCore"),
        .executableTarget(name: "Viper", dependencies: ["ViperCore"]),
        .testTarget(name: "ViperCoreTests", dependencies: ["ViperCore"])
    ]
)
