// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenHabitCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "OpenHabitCore", targets: ["OpenHabitCore"])],
    targets: [.target(name: "OpenHabitCore"), .testTarget(name: "OpenHabitCoreTests", dependencies: ["OpenHabitCore"])]
)
