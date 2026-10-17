// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pulse",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Pulse", targets: ["Pulse"])],
    targets: [
        .target(name: "PulseCore"),
        .executableTarget(name: "Pulse", dependencies: ["PulseCore"]),
        .executableTarget(name: "PulseCoreChecks", dependencies: ["PulseCore"], path: "Tests/PulseCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
