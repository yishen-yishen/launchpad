// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "LaunchDock", platforms: [.macOS("26.0")], products: [.library(name: "LaunchDockCore", targets: ["LaunchDockCore"]), .executable(name: "LaunchDock", targets: ["LaunchDock"])], targets: [.target(name: "LaunchDockCore"), .executableTarget(name: "LaunchDock", dependencies: ["LaunchDockCore"]), .executableTarget(name: "CoreChecks", dependencies: ["LaunchDockCore"], path: "Checks"), .testTarget(name: "LaunchDockCoreTests", dependencies: ["LaunchDockCore"])])
