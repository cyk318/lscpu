// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lscpu",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Lscpu", targets: ["Lscpu"])],
    targets: [
        .target(name: "LscpuCore"),
        .executableTarget(name: "Lscpu", dependencies: ["LscpuCore"]),
        .executableTarget(name: "LscpuCoreChecks", dependencies: ["LscpuCore"], path: "Tests/LscpuCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
